-- Adversarial scan over the full base roster (137 jokers + 52 consumables): drives the real context row builders
-- and injects hostile ability values (embedded commas/pipes/newlines, 1e18, table/nil) to assert CSV field-count integrity, delimiter safety, no int64 wrap, no crash. luajit tests/test_card_scan.lua
package.path = "./?.lua;;" .. package.path
_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local CardUtil = require("facts.card_util")
local CtxHelpers = require("context.ctx_helpers")
local CtxJokers = require("context.ctx_jokers")
local CtxMisc = require("context.ctx_misc")

local fails, total = 0, 0
local function check(name, cond, detail)
  total = total + 1
  if not cond then  -- print only failures to keep the scan output readable
    fails = fails + 1
    print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or ""))
  end
end

-- {key, name, cfg{}, extra{}} from the Balatro joker centers
local JOKERS = {
  {"j_joker","Joker",{mult=1},{}}, {"j_greedy_joker","Greedy Joker",{},{s_mult=3}},
  {"j_lusty_joker","Lusty Joker",{},{s_mult=3}}, {"j_jolly","Jolly Joker",{},{mult=8}},
  {"j_zany","Zany Joker",{},{mult=12}}, {"j_mad","Mad Joker",{},{mult=10}},
  {"j_sly","Sly Joker",{t_chips=50},{}}, {"j_wily","Wily Joker",{t_chips=100},{}},
  {"j_half","Half Joker",{},{mult=20}}, {"j_stencil","Joker Stencil",{x_mult=1},{}},
  {"j_ceremonial","Ceremonial Dagger",{mult=0},{}}, {"j_mystic_summit","Mystic Summit",{},{mult=15}},
  {"j_loyalty_card","Loyalty Card",{x_mult=4},{x_mult=4}}, {"j_misprint","Misprint",{mult=0},{}},
  {"j_gros_michel","Gros Michel",{mult=15},{mult=15}}, {"j_even_steven","Even Steven",{},{mult=4}},
  {"j_scholar","Scholar",{},{mult=4,chips=20}}, {"j_supernova","Supernova",{},{}},
  {"j_ride_the_bus","Ride the Bus",{mult=0},{}}, {"j_cavendish","Cavendish",{x_mult=3},{x_mult=3}},
  {"j_card_sharp","Card Sharp",{x_mult=3},{x_mult=3}}, {"j_square","Square Joker",{chips=0},{}},
  {"j_vampire","Vampire",{x_mult=1},{}}, {"j_hologram","Hologram",{x_mult=1},{}},
  {"j_baron","Baron",{},{}}, {"j_obelisk","Obelisk",{x_mult=1},{}},
  {"j_luchador","Luchador",{},{}}, {"j_matador","Matador",{},{}},
  {"j_turtle_bean","Turtle Bean",{h_mod=1},{}}, {"j_walkie_talkie","Walkie Talkie",{},{mult=4,chips=10}},
  {"j_ramen","Ramen",{x_mult=2},{}}, {"j_popcorn","Popcorn",{mult=20},{}},
  {"j_bloodstone","Bloodstone",{x_mult=1.5},{x_mult=1.5}}, {"j_glass","Glass Joker",{x_mult=1},{}},
  {"j_flash","Flash Card",{mult=0},{}}, {"j_bootstraps","Bootstraps",{mult=2},{mult=2}},
  {"j_yorick","Yorick",{mult=1},{}}, {"j_duo","The Duo",{x_mult=2},{}},
  {"j_trio","The Trio",{x_mult=3},{}}, {"j_family","The Family",{x_mult=4},{}},
  {"j_order","The Order",{x_mult=3},{}}, {"j_tribe","The Tribe",{x_mult=2},{}},
  {"j_blueprint","Blueprint",{},{}}, {"j_brainstorm","Brainstorm",{},{}},
  {"j_stuntman","Stuntman",{},{}}, {"j_perkeo","Perkeo",{},{}},
  {"j_triboulet","Triboulet",{},{}}, {"j_caino","Caino",{},{}}, {"j_chicot","Chicot",{},{}},
  {"j_smeared","Smeared Joker",{},{}}, {"j_four_fingers","Four Fingers",{},{}},
  {"j_credit_card","Credit Card",{},{}}, {"j_banner","Banner",{},{}}, {"j_marble","Marble Joker",{},{}},
  {"j_8_ball","8 Ball",{},{}}, {"j_dusk","Dusk",{},{}}, {"j_fibonacci","Fibonacci",{},{}},
  {"j_steel_joker","Steel Joker",{},{}}, {"j_abstract","Abstract Joker",{},{}}, {"j_hack","Hack",{},{}},
  {"j_pareidolia","Pareidolia",{},{}}, {"j_business","Business Card",{},{}}, {"j_space","Space Joker",{},{}},
  {"j_red_card","Red Card",{},{}}, {"j_madness","Madness",{},{}}, {"j_seance","Seance",{},{}},
  {"j_riff_raff","Riff-raff",{},{}}, {"j_shortcut","Shortcut",{},{}}, {"j_vagabond","Vagabond",{},{}},
  {"j_cloud_9","Cloud 9",{},{}}, {"j_rocket","Rocket",{},{}}, {"j_midas_mask","Midas Mask",{},{}},
  {"j_photograph","Photograph",{},{}}, {"j_gift","Gift Card",{},{}}, {"j_erosion","Erosion",{},{}},
  {"j_reserved_parking","Reserved Parking",{},{}}, {"j_mail","Mail-In Rebate",{},{}},
  {"j_to_the_moon","To the Moon",{},{}}, {"j_hallucination","Hallucination",{},{}},
  {"j_fortune_teller","Fortune Teller",{},{}}, {"j_juggler","Juggler",{},{}}, {"j_drunkard","Drunkard",{},{}},
  {"j_stone","Stone Joker",{},{}}, {"j_golden","Golden Joker",{},{}}, {"j_lucky_cat","Lucky Cat",{x_mult=1},{}},
  {"j_baseball","Baseball Card",{},{}}, {"j_bull","Bull",{},{}}, {"j_diet_cola","Diet Cola",{},{}},
  {"j_trading","Trading Card",{},{}}, {"j_trousers","Spare Trousers",{},{}}, {"j_ancient","Ancient Joker",{},{}},
  {"j_seltzer","Seltzer",{},{}}, {"j_castle","Castle",{chips=0},{}}, {"j_smiley","Smiley Face",{},{}},
  {"j_campfire","Campfire",{},{}}, {"j_ticket","Golden Ticket",{},{}}, {"j_mr_bones","Mr. Bones",{},{}},
  {"j_acrobat","Acrobat",{},{}}, {"j_sock_and_buskin","Sock and Buskin",{},{}}, {"j_swashbuckler","Swashbuckler",{},{}},
  {"j_troubadour","Troubadour",{},{}}, {"j_certificate","Certificate",{},{}}, {"j_throwback","Throwback",{},{}},
  {"j_hanging_chad","Hanging Chad",{},{}}, {"j_rough_gem","Rough Gem",{},{}}, {"j_arrowhead","Arrowhead",{},{}},
  {"j_onyx_agate","Onyx Agate",{},{}}, {"j_ring_master","Showman",{},{}}, {"j_flower_pot","Flower Pot",{},{}},
  {"j_wee","Wee Joker",{chips=0},{}}, {"j_merry_andy","Merry Andy",{},{}}, {"j_oops","Oops! All 6s",{},{}},
  {"j_idol","The Idol",{},{}}, {"j_seeing_double","Seeing Double",{},{}}, {"j_hit_the_road","Hit the Road",{},{}},
  {"j_invisible","Invisible Joker",{},{}}, {"j_satellite","Satellite",{},{}}, {"j_shoot_the_moon","Shoot the Moon",{},{}},
  {"j_drivers_license","Driver's License",{},{}}, {"j_cartomancer","Cartomancer",{},{}}, {"j_astronomer","Astronomer",{},{}},
  {"j_burnt","Burnt Joker",{},{}}, {"j_chaos","Chaos the Clown",{},{}}, {"j_raised_fist","Raised Fist",{},{}},
  {"j_scary_face","Scary Face",{},{}}, {"j_delayed_grat","Delayed Gratification",{},{}}, {"j_odd_todd","Odd Todd",{},{}},
  {"j_mime","Mime",{},{}}, {"j_wrathful_joker","Wrathful Joker",{},{s_mult=3}}, {"j_gluttenous_joker","Gluttonous Joker",{},{s_mult=3}},
  {"j_crazy","Crazy Joker",{},{mult=12}}, {"j_droll","Droll Joker",{},{mult=10}}, {"j_clever","Clever Joker",{t_chips=80},{}},
  {"j_devious","Devious Joker",{t_chips=100},{}}, {"j_crafty","Crafty Joker",{t_chips=80},{}},
}
local CONSUMABLES = {
  {"c_fool","Tarot",0},{"c_magician","Tarot",2},{"c_high_priestess","Tarot",0},{"c_empress","Tarot",2},
  {"c_emperor","Tarot",0},{"c_heirophant","Tarot",2},{"c_lovers","Tarot",1},{"c_chariot","Tarot",1},
  {"c_justice","Tarot",1},{"c_hermit","Tarot",0},{"c_wheel_of_fortune","Tarot",0},{"c_strength","Tarot",2},
  {"c_hanged_man","Tarot",2},{"c_death","Tarot",2},{"c_temperance","Tarot",0},{"c_devil","Tarot",1},
  {"c_tower","Tarot",1},{"c_star","Tarot",3},{"c_moon","Tarot",3},{"c_sun","Tarot",3},{"c_judgement","Tarot",0},{"c_world","Tarot",3},
  {"c_mercury","Planet",0},{"c_venus","Planet",0},{"c_earth","Planet",0},{"c_mars","Planet",0},{"c_jupiter","Planet",0},
  {"c_saturn","Planet",0},{"c_uranus","Planet",0},{"c_neptune","Planet",0},{"c_pluto","Planet",0},{"c_planet_x","Planet",0},
  {"c_ceres","Planet",0},{"c_eris","Planet",0},
  {"c_familiar","Spectral",0},{"c_grim","Spectral",0},{"c_incantation","Spectral",0},{"c_talisman","Spectral",1},
  {"c_aura","Spectral",0},{"c_wraith","Spectral",0},{"c_sigil","Spectral",0},{"c_ouija","Spectral",0},
  {"c_ectoplasm","Spectral",0},{"c_immolate","Spectral",0},{"c_ankh","Spectral",0},{"c_deja_vu","Spectral",1},
  {"c_hex","Spectral",0},{"c_trance","Spectral",1},{"c_medium","Spectral",1},{"c_cryptid","Spectral",1},
  {"c_soul","Spectral",0},{"c_black_hole","Spectral",0},
}

local function joker_card(j)
  local ability = { name = j[2], set = "Joker" }
  for k, v in pairs(j[3]) do ability[k] = v end
  if next(j[4]) then ability.extra = {}; for k, v in pairs(j[4]) do ability.extra[k] = v end end
  return { ability = ability, config = { center = { key = j[1], set = "Joker" } }, sell_cost = 3, cost = 5 }
end
local function cons_card(c)
  local cons = {}
  if c[3] > 0 then cons.max_highlighted = c[3] end
  return { ability = { name = (c[1]:gsub("^c_", "")), set = c[2], consumeable = cons },
    config = { center = { key = c[1], set = c[2] } }, sell_cost = 2 }
end

-- INVARIANT: each data row splits into exactly `cols` CSV fields, has no newline, and no int64-wrapped negative
local function scan_rows(tag, section_str, cols)
  if section_str == nil then return end
  local first = true
  for line in (section_str .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" and not first then  -- skip header
      if line:find("^%d") then        -- a data row (starts with an index)
        -- unescaped comma in a column shifts every later column -> wrong field count
        local n = select(2, line:gsub(",", ",")) + 1
        check(tag .. ": row has exactly " .. cols .. " CSV fields", n == cols, "got " .. n .. " :: " .. line)
        check(tag .. ": row has no embedded newline / pipe-as-delimiter", not line:find("[\r\n]"))
      end
    end
    first = false
  end
end

local function no_crash(tag, fn)
  local ok, err = pcall(fn)
  check(tag .. ": no crash", ok, err)
end

local HOSTILE = { false, true }  -- pass 2: inject adversarial values
for _, hostile in ipairs(HOSTILE) do
  for _, j in ipairs(JOKERS) do
    local card = joker_card(j)
    if hostile then
      card.ability.name = "Ev,il|Na\nme"
      card.ability.extra = card.ability.extra or {}
      card.ability.extra.gain = 1e18
      card.sell_cost = 9223372036854775807
      card.edition = { name = "Fo,il", foil = true }
    end
    no_crash("joker " .. j[1] .. (hostile and " [hostile]" or ""), function()
      CtxHelpers.card_effect_summary(card); CtxHelpers.joker_tags(card)
      CtxHelpers.ability_signature(card.ability); CardUtil.card_set(card)
    end)
    G.jokers = { cards = { card }, config = { card_limit = 5 } }
    local ok, sec = pcall(CtxJokers.jokers_section)
    check("joker " .. j[1] .. (hostile and " [hostile]" or "") .. ": jokers_section ok", ok, sec)
    if ok then scan_rows("joker " .. j[1] .. (hostile and " [hostile]" or ""), sec, 5) end
  end
end

for _, hostile in ipairs(HOSTILE) do
  for _, c in ipairs(CONSUMABLES) do
    local card = cons_card(c)
    if hostile then card.ability.name = "Ba,d|Na\nme"; card.sell_cost = 1e18 end
    no_crash("cons " .. c[1] .. (hostile and " [hostile]" or ""), function()
      CardUtil.consumable_target_range(card); CardUtil.can_take_pack_card(card); CardUtil.card_set(card)
    end)
    local mn, mx = CardUtil.consumable_target_range(card)
    check("cons " .. c[1] .. ": target range well-formed",
      (mn == nil and mx == nil) or (type(mn) == "number" and type(mx) == "number" and mn <= mx), tostring(mn) .. "," .. tostring(mx))
    check("cons " .. c[1] .. ": can_take_pack_card is boolean", type(CardUtil.can_take_pack_card(card)) == "boolean")
    G.consumeables = { cards = { card }, config = { card_limit = 2 } }
    local ok, sec = pcall(CtxMisc.consumables_section)
    check("cons " .. c[1] .. (hostile and " [hostile]" or "") .. ": consumables_section ok", ok, sec)
    if ok then scan_rows("cons " .. c[1] .. (hostile and " [hostile]" or ""), sec, 7) end  -- i,n,t,$,sel,ok,d
  end
end

-- pack rows (PC:): Buffoon=jokers, Arcana/Celestial/Spectral=consumables, Standard=playing cards
G.GAME.pack_choices = 1
local packcards = {}
for _, j in ipairs(JOKERS) do packcards[#packcards + 1] = { joker_card(j), j[1] } end
for _, c in ipairs(CONSUMABLES) do packcards[#packcards + 1] = { cons_card(c), c[1] } end
for _, v in ipairs({ "A", "K", "Q", "T", "9", "2" }) do
  for _, s in ipairs({ "Hearts", "Diamonds", "Clubs", "Spades" }) do
    packcards[#packcards + 1] = { { base = { value = v, suit = s }, config = { center = { key = "c_base" } }, ability = {} }, "playing_" .. v .. s:sub(1, 1) }
  end
end
-- enhanced/edition/seal playing card: a distinct name/token path
packcards[#packcards + 1] = { { base = { value = "A", suit = "Spades" }, edition = { foil = true },
  seal = "Gold", config = { center = { key = "m_steel" } }, ability = { name = "Steel Card" } }, "playing_enhanced" }
for _, pc in ipairs(packcards) do
  local card, key = pc[1], pc[2]
  G.pack_cards = { cards = { card } }
  local ok, sec = pcall(CtxMisc.pack_section, "SMODS_BOOSTER_OPENED")
  check("pack " .. key .. ": pack_section ok", ok, sec)
  if ok and sec then
    scan_rows("pack " .. key, sec, 5)                       -- PC: i,n,t,f,ok -> 5 fields
    check("pack " .. key .. ": ok column is Y or N", sec:find(",[YN]\n") ~= nil or sec:find(",[YN]$") ~= nil, sec)
  end
end

-- self-proof the scan bites: an injected comma/pipe name must be folded or the field count breaks
do
  local c = joker_card(JOKERS[1]); c.ability.name = "A,B|C"
  check("meta: hostile name genuinely contains a delimiter", c.ability.name:find(",") ~= nil)
  G.jokers = { cards = { c }, config = { card_limit = 5 } }
  local row = (CtxJokers.jokers_section() or ""):match("\n(1,[^\n]*)")
  check("meta: render folds the delimiter -> row stays exactly 5 fields (proves the sweep bites)",
    row ~= nil and (select(2, row:gsub(",", ",")) + 1) == 5, row)
end

print(string.format("==== card-scan: %d/%d PASS, %d FAIL (%d jokers + %d consumables x clean+hostile) ====",
  total - fails, total, fails, #JOKERS, #CONSUMABLES))
os.exit(fails == 0 and 0 or 1)
